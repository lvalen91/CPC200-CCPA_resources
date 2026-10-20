import socket,sys
s=socket.socket(); s.setsockopt(socket.SOL_SOCKET,socket.SO_REUSEADDR,1); s.bind(('10.10.10.100',5611)); s.listen(1); s.settimeout(40)
c,_=s.accept(); d=open(sys.argv[1],'rb').read(); c.sendall(d); c.shutdown(socket.SHUT_WR)
c.settimeout(5)
try: c.recv(1)
except Exception: pass
c.close()
