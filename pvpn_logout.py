import socket, json

try:
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(3)
    s.connect("/run/pvpn/pvpn.sock")
    s.sendall(json.dumps({"command": "logout"}).encode() + b"\n")
    print(s.recv(1024).decode())
    s.close()
except Exception as e:
    print(e)
