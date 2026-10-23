import httpx
import pytest
from fastapi import HTTPException
from app.providers.routing import TomTomRoutingProvider


@pytest.mark.asyncio
@pytest.mark.parametrize('path',['map/1/tile/basic/main/13/6504/3606.png','traffic/map/4/tile/flow/relative0/13/6504/3606.png'])
async def test_tile_timeout_does_not_double_failed_burst(path):
    calls=[]
    def handler(request):
        calls.append(request)
        raise httpx.ConnectTimeout('offline')
    async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
        with pytest.raises(HTTPException) as error:
            await TomTomRoutingProvider(client,'test-key').get(path,{})
    assert error.value.status_code==504
    assert len(calls)==1
