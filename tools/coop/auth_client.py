import hashlib
import secrets
import socket
import struct


def authenticate(account, password, port=3724):
    account = account.upper().encode("ascii")
    password = password.upper().encode("ascii")
    digest = lambda value: hashlib.sha1(value).digest()
    number = lambda value: int.from_bytes(value, "little")
    with socket.create_connection(("127.0.0.1", port), timeout=20) as connection:
        def read(count):
            data = bytearray()
            while len(data) < count:
                part = connection.recv(count - len(data))
                if not part:
                    raise EOFError("Login connection closed")
                data.extend(part)
            return bytes(data)

        body = b"WoW\0" + bytes([1, 12, 1]) + struct.pack("<H", 5875)
        body += b"68x\0niW\0SUne" + struct.pack("<II", 0, 0x0100007f)
        body += bytes([len(account)]) + account
        connection.sendall(b"\0\x08" + struct.pack("<H", len(body)) + body)
        reply = read(3)
        assert reply == b"\0\0\0", ("Login challenge refused", reply.hex())
        host_public = read(32)
        generator_bytes = read(read(1)[0])
        prime_bytes = read(read(1)[0])
        salt = read(32)
        read(16)
        assert read(1) == b"\0", "Unexpected login PIN challenge"
        prime, generator = number(prime_bytes), number(generator_bytes)
        private = secrets.randbits(256)
        public = pow(generator, private, prime).to_bytes(32, "little")
        x = number(digest(salt + digest(account + b":" + password)))
        u = number(digest(public + host_public))
        shared = pow((number(host_public) - 3 * pow(generator, x, prime)) % prime, private + u * x, prime).to_bytes(32, "little")
        skipped = len(shared) - len(shared.lstrip(b"\0"))
        skipped += skipped % 2
        even = digest(shared[skipped::2])
        odd = digest(shared[skipped + 1::2])
        key = bytes(value for pair in zip(even, odd) for value in pair)
        xor = bytes(a ^ b for a, b in zip(digest(prime_bytes), digest(generator_bytes))).rstrip(b"\0")
        proof = digest(xor + digest(account) + salt + public + host_public + key)
        connection.sendall(b"\x01" + public + proof + bytes(20) + b"\0\0")
        result = read(2)
        assert result == b"\x01\0", ("Login password refused", result.hex())
        assert read(20) == digest(public + proof + key), "Invalid server login proof"
        read(4)
        connection.sendall(b"\x10" + bytes(4))
        assert read(1) == b"\x10", "Missing realm list"
        realms = read(struct.unpack("<H", read(2))[0])
        assert b"127.0.0.1:8085\0" in realms, "Realm must use the local tunnel"
        return key
