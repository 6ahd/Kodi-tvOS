import importlib.util
import json
import sys
import tempfile
import types
from pathlib import Path

base = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    marker = root / 'addon_data/script.dexhub.tvos.players/appletv-repository-v1.done'
    old = root / 'repository.dexhub'
    old.mkdir()
    descriptor = old / 'addon.xml'
    calls = []
    failure = False
    present = True

    def addon(identifier):
        if identifier == 'repository.dexhub' and not present:
            raise RuntimeError('Not installed')
        return types.SimpleNamespace(getAddonInfo=lambda _: str(old))

    def rpc(raw):
        request = json.loads(raw)
        calls.append(request['params'])
        return json.dumps({'error': {'message': 'fixture'}} if failure else {'result': 'OK'})

    def path(value):
        return root / value.removeprefix('special://profile/') if value.startswith('special://') else Path(value)

    class File:
        def __init__(self, value, mode='r'):
            self.file = path(value).open(mode)
        def read(self): return self.file.read()
        def write(self, text): return self.file.write(text)
        def close(self): self.file.close()

    sys.modules['xbmc'] = types.SimpleNamespace(executeJSONRPC=rpc, log=lambda *a: None, LOGINFO=1)
    sys.modules['xbmcaddon'] = types.SimpleNamespace(Addon=addon)
    sys.modules['xbmcvfs'] = types.SimpleNamespace(
        exists=lambda value: path(value).exists(), File=File,
        mkdirs=lambda value: path(value).mkdir(parents=True, exist_ok=True))
    spec = importlib.util.spec_from_file_location('repository_setup', base / 'script.dexhub.tvos.players/repository_setup.py')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    descriptor.write_text('<addon><extension><dir><info>https://dexworld.cc/dexhub/addons.xml</info></dir></extension></addon>')
    assert module.migrate() and not module.migrate()
    assert calls == [{'addonid': 'repository.dexworld.appletv', 'enabled': True},
                     {'addonid': 'repository.dexhub', 'enabled': False}]
    marker.unlink()
    calls.clear()
    descriptor.write_text('<addon><extension><dir><info>https://other.example/addons.xml</info></dir></extension></addon>')
    assert module.migrate() and len(calls) == 1
    marker.unlink()
    present = False
    assert module.migrate()
    marker.unlink()
    failure = True
    try:
        module.migrate()
    except RuntimeError:
        pass
    else:
        raise AssertionError('Failed repository migration accepted')
    assert not marker.exists()
print('PASS: Apple TV repository migration, old-source disabling, custom source preservation, idempotency and retry')
