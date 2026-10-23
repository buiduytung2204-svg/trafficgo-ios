import asyncio
import sqlite3
import httpx
import pytest
from fastapi import HTTPException
from app.providers.search import SearchBudget
from app.providers.geo_tiles import GeoapifyTiles
from test_api import client


def test_shared_credits_and_migration(tmp_path):
    path=str(tmp_path/'budget.db')
    with sqlite3.connect(path) as db:
        db.execute('CREATE TABLE days(day TEXT PRIMARY KEY,used INTEGER NOT NULL)')
        db.execute("INSERT INTO days VALUES (date('now'),1)")
    b=SearchBudget(path,100,credit_limit=2)
    assert b.snapshot()['credits_used']==1
    for _ in range(4):b.reserve('tile')
    assert b.snapshot()['credits_used']==2
    with pytest.raises(HTTPException) as e:b.reserve('tile')
    assert e.value.status_code==429
    assert SearchBudget(path,100,2).snapshot()['credits_used']==2


def test_geo_tiles_auth_and_independent_of_tomtom(client):
    from app.main import daily,settings
    daily['count']=settings.daily_provider_budget
    class Tiles:
        async def tile(self,z,x,y):return b'\x89PNG\r\n\x1a\ndata',True
    client.app.state.geo_tiles=Tiles()
    assert client.get('/api/v1/geo/tiles/13/6504/3606.png',headers={'X-App-Token':'wrong'}).status_code==401
    response=client.get('/api/v1/geo/tiles/13/6504/3606.png')
    assert response.status_code==200 and response.headers['content-type']=='image/png'


@pytest.mark.asyncio
async def test_tile_cache_coalescing_and_no_secret(tmp_path):
    calls=[]
    def handler(r):
        calls.append(r)
        return httpx.Response(200,content=b'\x89PNG\r\n\x1a\ndata',headers={'content-type':'image/png','cache-control':'public,max-age=60'})
    b=SearchBudget(str(tmp_path/'b.db'),100)
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as c:
        p=GeoapifyTiles(c,'test-key',b)
        result=await asyncio.gather(*(p.tile(13,6504,3606) for _ in range(4)))
        assert len(calls)==1 and sum(hit for _,hit in result)==3
        assert (await p.tile(13,6504,3606))[1]
        assert len(calls)==1 and b.snapshot()['credits_used']==.25
        assert 'test-key' not in str(p.cache)


@pytest.mark.asyncio
async def test_no_store_is_not_cached_and_invalid_tile_rejected(tmp_path):
    calls=[]
    def handler(r):
        calls.append(r)
        return httpx.Response(200,content=b'\x89PNG\r\n\x1a\ndata',headers={'content-type':'image/png','cache-control':'no-store'})
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as c:
        p=GeoapifyTiles(c,'key',SearchBudget(str(tmp_path/'b.db'),100))
        await p.tile(13,6504,3606);await p.tile(13,6504,3606)
        assert not p.cache and len(calls)==2
        with pytest.raises(HTTPException) as e:await p.tile(3,9,1)
        assert e.value.status_code==422
