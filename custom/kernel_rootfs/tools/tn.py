import socket,sys,time
host,port=sys.argv[1],int(sys.argv[2]); cmds=sys.argv[3]
import os
if os.environ.get('BOUND_IF'):
    s=socket.socket(); s.settimeout(8); s.setsockopt(socket.IPPROTO_IP,25,socket.if_nametoindex(os.environ['BOUND_IF'])); s.connect((host,port))  # 25 = IP_BOUND_IF (macOS)
else:
    s=socket.create_connection((host,port),timeout=8)
s.settimeout(1.5)
def drain(t=1.5):
    out=b''; end=time.time()+t
    while time.time()<end:
        try: d=s.recv(4096)
        except socket.timeout: break
        if not d: break
        i=0; clean=b''
        while i<len(d):
            if d[i]==255 and i+2<len(d) and d[i+1] in (251,252,253,254):
                s.sendall(bytes([255, 252 if d[i+1] in (253,254) else 254, d[i+2]])); i+=3
            elif d[i]==255 and i+1<len(d): i+=2
            else: clean+=d[i:i+1]; i+=1
        out+=clean
    return out
drain(1.5)
s.sendall((cmds+"\n").encode()); time.sleep(0.5)
print(drain(float(sys.argv[4]) if len(sys.argv)>4 else 4).decode('latin1'))
