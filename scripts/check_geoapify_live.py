"""Opt-in three local HTTP calls: two real searches and one cache hit.

Needs a running backend with SEARCH_PROVIDER=geoapify. Never prints API keys,
tokens, upstream URLs, raw user queries or user GPS. Uses fixed public POIs.
"""
import json
from pathlib import Path
import sys
import time
import httpx

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'backend'))
from app.config import Settings


def main():
    config=Settings(_env_file=ROOT/'backend/.env')
    with httpx.Client(base_url='http://127.0.0.1:8000',timeout=15,
                      headers={'X-App-Token':config.app_access_token}) as client:
        before=client.get('/api/v1/diagnostics').json()['geoapify']
        rows=[]
        for query in ['NHS Trung Văn','NHS Trung Văn','Trường Đại học CMC cơ sở 2']:
            started=time.perf_counter()
            response=client.get('/api/v1/places/search',params={'q':query})
            if response.status_code!=200:
                raise SystemExit(f'Search check failed: HTTP {response.status_code}')
            data=response.json()
            assert data.get('provider')=='geoapify'
            assert data['places'], 'Expected named public place not found'
            rows.append({'query':query,'http':response.status_code,
                'elapsed_ms':round((time.perf_counter()-started)*1000,1),
                'names':[p['name'] for p in data['places']]})
        after=client.get('/api/v1/diagnostics').json()['geoapify']
        print(json.dumps({'checks':rows,'upstream_attempt_delta':after['used']-before['used'],
                          'cache_hit_delta':after['cache_hits']-before['cache_hits'],
                          'budget':after},ensure_ascii=True,indent=2))


if __name__=='__main__':main()
