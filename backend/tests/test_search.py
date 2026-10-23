import asyncio
import httpx
import pytest
from fastapi import HTTPException
from app.providers.search import GeoapifySearchProvider, SearchBudget
from test_api import client


def response():
    return {'results':[
        {'name':'NHS Trung Văn','formatted':'Tố Hữu','lat':20.9893201,'lon':105.7821709,
         'datasource':{'attribution':'© OpenStreetMap contributors'}},
        {'name':'NHS Trung Văn','formatted':'Tố Hữu','lat':20.989233,'lon':105.782231},
        {'name':'Outside','formatted':'Outside','lat':10,'lon':106}]}


@pytest.mark.asyncio
async def test_cache_coalescing_dedupe_normalization(tmp_path):
    calls=[]
    async def handler(request):
        calls.append(request)
        assert request.url.params['filter']=='rect:105.2,20.5,106.3,21.6'
        await asyncio.sleep(.01)
        return httpx.Response(200,json=response())
    budget=SearchBudget(str(tmp_path/'budget.db'),10)
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as c:
        p=GeoapifySearchProvider(c,'test-key',budget)
        answers=await asyncio.gather(*(p.search('  NHS   Trung Văn ',21.0285,105.8542) for _ in range(4)))
        assert len(calls)==1 and len(answers[0])==1 and p.coalesced==3
        assert answers[0][0]['provider']=='geoapify'
        assert answers[0][0]['datasource']['attribution']=='© OpenStreetMap contributors'
        assert await p.search('nhs trung văn',21.029,105.854)==answers[0]
        assert p.cache_hits==1 and budget.snapshot()['used']==1
        assert await p.search('ab',21,105)==[]


def test_daily_budget_persists_and_does_not_reset_on_restart(tmp_path):
    path=str(tmp_path/'budget.db')
    SearchBudget(path,1).reserve()
    restarted=SearchBudget(path,1)
    with pytest.raises(HTTPException) as error: restarted.reserve()
    assert error.value.status_code==429 and restarted.snapshot()['used']==1


def test_rate_limit_and_failed_store_are_closed(tmp_path):
    budget=SearchBudget(str(tmp_path/'budget.db'),100)
    budget.reserve();budget.reserve()
    with pytest.raises(HTTPException) as error:budget.reserve()
    assert error.value.status_code==429 and budget.snapshot()['used']==2
    budget.filename=str(tmp_path/'missing'/'budget.db')
    with pytest.raises(HTTPException) as error:budget.reserve()
    assert error.value.status_code==503


@pytest.mark.asyncio
@pytest.mark.parametrize('status',[401,403,429,500])
async def test_upstream_error_no_retry_or_cache(tmp_path,status):
    calls=[]
    def handler(r):calls.append(r);return httpx.Response(status,headers={'Retry-After':'120'})
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as c:
        p=GeoapifySearchProvider(c,'key',SearchBudget(str(tmp_path/'b.db'),10))
        with pytest.raises(HTTPException) as error:await p.search('query',21,105.8)
        assert error.value.status_code==(429 if status==429 else 502)
        assert len(calls)==1 and not p.cache
        if status==429:
            with pytest.raises(HTTPException):await p.search('different',21,105.8)
            assert len(calls)==1


@pytest.mark.asyncio
async def test_timeout_and_malformed(tmp_path):
    def handler(r):raise httpx.ReadTimeout('offline')
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as c:
        p=GeoapifySearchProvider(c,'key',SearchBudget(str(tmp_path/'b.db'),10))
        with pytest.raises(HTTPException) as error:await p.search('query',21,105.8)
        assert error.value.status_code==504 and not p.cache
    async with httpx.AsyncClient(transport=httpx.MockTransport(lambda r:httpx.Response(200,json={}))) as c:
        p=GeoapifySearchProvider(c,'key',SearchBudget(str(tmp_path/'c.db'),10))
        with pytest.raises(HTTPException) as error:await p.search('query',21,105.8)
        assert error.value.status_code==502 and not p.cache


def test_search_auth_and_geo_not_blocked_by_tomtom_budget(client,monkeypatch):
    from app.main import settings,daily
    monkeypatch.setattr(settings,'search_provider','geoapify')
    daily['count']=settings.daily_provider_budget
    class Search:
        async def search(self,q,lat,lon):return []
    client.app.state.search=Search()
    assert client.get('/api/v1/places/search?q=test',headers={'X-App-Token':'wrong'}).status_code==401
    assert client.get('/api/v1/places/search?q=test').status_code==200
