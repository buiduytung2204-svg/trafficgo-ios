"""Small authorized local HTTP trace. NOT a browser/render or road-navigation test.

Run with backend/.venv/Scripts/python scripts/benchmark_http.py --output docs/benchmarks/after-http.json
At most 37 incoming requests + two diagnostics calls; provider retries can add attempts.
"""
import argparse
import asyncio
import json
import math
from pathlib import Path
import subprocess
import sys
import time
import httpx

root = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(root/'backend'))
from app.config import Settings


def summarize(rows):
    values = sorted(row['ms'] for row in rows)
    return {'requests':len(rows),'p50_ms':values[math.ceil(len(values)*.5)-1],
            'p95_ms':values[math.ceil(len(values)*.95)-1],
            'errors':sum(row['status']!=200 for row in rows),
            'error_rate':sum(row['status']!=200 for row in rows)/len(rows)}


async def benchmark(base_url, output):
    settings = Settings(_env_file=root/'backend/.env')
    rows=[]
    async with httpx.AsyncClient(base_url=base_url,headers={'X-App-Token':settings.app_access_token},timeout=30) as client:
        async def diagnostics():
            response=await client.get('/api/v1/diagnostics')
            return response.json() if response.status_code==200 else None
        before=await diagnostics()
        async def request(phase,kind,path,body=None):
            start=time.perf_counter()
            try:
                response=await (client.post(path,json=body) if body is not None else client.get(path))
                row={'phase':phase,'kind':kind,'status':response.status_code,'ms':round((time.perf_counter()-start)*1000,2),
                     'bytes':len(response.content),'server_timing':response.headers.get('server-timing'),
                     'rate_limit_bucket':response.headers.get('x-ratelimit-bucket'),
                     'coalesced':response.headers.get('x-tile-coalesced')=='true'}
            except httpx.RequestError as error:
                row={'phase':phase,'kind':kind,'status':0,'ms':round((time.perf_counter()-start)*1000,2),'error':type(error).__name__}
            rows.append(row)
        lat,lon,z=21.0285,105.8542,13
        x=int((lon+180)/360*2**z)
        y=int((1-math.asinh(math.tan(math.radians(lat)))/math.pi)/2*2**z)
        for phase,zz,xx,yy in [('open',z,x,y),('pan',z,x+1,y),('zoom',z+1,x*2,y*2),('navigation_refresh',z+1,x*2,y*2)]:
            for kind in ('map','traffic'):
                await asyncio.gather(*(request(phase,kind,f'/api/v1/tiles/{kind}/{zz}/{xx+dx}/{yy+dy}.png')
                                      for dx,dy in [(0,0),(1,0),(0,1),(1,1)]))
        await request('route','routing','/api/v1/routes/calculate',{
            'origin':{'lat':lat,'lon':lon},'destination':{'lat':21.0378,'lon':105.8347},'vehicle':'car'})
        await asyncio.gather(*(request('duplicates','traffic','/api/v1/tiles/traffic/13/6504/3606.png') for _ in range(4)))
        after=await diagnostics()
    counts={}
    if before and after:
        for name,metric in after['metrics'].items():
            counts[name]=metric['requests']-before['metrics'].get(name,{}).get('requests',0)
    report={'revision':subprocess.check_output(['git','rev-parse','--short','HEAD'],cwd=root,text=True).strip(),
            'branch':subprocess.check_output(['git','branch','--show-current'],cwd=root,text=True).strip(),
            'working_tree_modified':bool(subprocess.check_output(['git','status','--porcelain'],cwd=root,text=True).strip()),
            'method':'controlled local HTTP trace; NOT browser gestures, rendering or real GPS navigation',
            'samples':rows,'summary':{phase:summarize([r for r in rows if r['phase']==phase]) for phase in dict.fromkeys(r['phase'] for r in rows)},
            'provider_request_counts':{name:count for name,count in counts.items() if name.startswith(('tomtom.','valhalla.'))},
            'render_ms':None,'diagnostics_after':after}
    output.parent.mkdir(parents=True,exist_ok=True)
    output.write_text(json.dumps(report,indent=2),encoding='utf-8')
    print(json.dumps({'summary':report['summary'],'provider_request_counts':report['provider_request_counts']}))


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-url',default='http://localhost:8000')
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    asyncio.run(benchmark(args.base_url,args.output))
