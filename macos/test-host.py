"""Exercise the actual installed native host on an ephemeral macOS CI runner."""
import json
import pathlib
import struct
import subprocess
import sys

app = pathlib.Path(sys.argv[1]).resolve()
host = app / "Contents/MacOS/TurnTablerChromeHost"
origin = "chrome-extension://ebnjhkdpohpgeipkalbfklpfibjadnhd/"


def request(message, extension=origin):
    payload = json.dumps(message).encode()
    result = subprocess.run([str(host), extension], input=struct.pack("<I", len(payload)) + payload,
                            capture_output=True, timeout=20, check=True)
    size, = struct.unpack("<I", result.stdout[:4])
    assert len(result.stdout) == size + 4, "Unexpected native messaging frame"
    return json.loads(result.stdout[4:])


reply = request({"action": "ping"})
assert reply["ok"] and reply["available"] and reply["protocol"] == 1, reply
assert pathlib.Path(reply["appPath"]) == app, reply
assert reply["appVersion"] == "1.1.0", reply
assert request({"action": "setPath", "appPath": str(app)})["available"]
assert not request({"action": "setPath", "appPath": "/Applications/Missing.app"})["ok"]
assert request({"action": "getSettings"})["appPath"] == str(app)
assert not request({"action": "play", "url": "https://youtube.com.evil.org/watch?v=2qfoSxRRCJc"})["ok"]
assert not request({"action": "ping"}, "chrome-extension://untrusted/")["ok"]
assert not request({"action": "unsupported"})["ok"]
print("PASS: macOS native host framing, saved path, version and request rejection")
