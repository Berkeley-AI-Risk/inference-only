"""Independent SHA-256 reference constants/algorithm, FIPS 180-4 §§4–6.

Source: https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.180-4.pdf
Constants transcribed from §4.2.2, not extracted from the implementation.
"""
K = tuple(int(word, 16) for word in '''
428a2f98 71374491 b5c0fbcf e9b5dba5 3956c25b 59f111f1 923f82a4 ab1c5ed5
d807aa98 12835b01 243185be 550c7dc3 72be5d74 80deb1fe 9bdc06a7 c19bf174
e49b69c1 efbe4786 0fc19dc6 240ca1cc 2de92c6f 4a7484aa 5cb0a9dc 76f988da
983e5152 a831c66d b00327c8 bf597fc7 c6e00bf3 d5a79147 06ca6351 14292967
27b70a85 2e1b2138 4d2c6dfc 53380d13 650a7354 766a0abb 81c2c92e 92722c85
a2bfe8a1 a81a664b c24b8b70 c76c51a3 d192e819 d6990624 f40e3585 106aa070
19a4c116 1e376c08 2748774c 34b0bcb5 391c0cb3 4ed8aa4a 5b9cca4f 682e6ff3
748f82ee 78a5636f 84c87814 8cc70208 90befffa a4506ceb bef9a3f7 c67178f2
'''.split())
IV = tuple(int(word,16) for word in '''
6a09e667 bb67ae85 3c6ef372 a54ff53a 510e527f 9b05688c 1f83d9ab 5be0cd19
'''.split())
MASK = (1 << 32) - 1


def rotr(x, n):
    return ((x >> n) | (x << (32-n))) & MASK


def compress(block, state):
    assert len(block) == 64 and len(state) == 8
    w = [int.from_bytes(block[n:n+4], 'big') for n in range(0,64,4)]
    for t in range(16,64):
        s0 = rotr(w[t-15],7) ^ rotr(w[t-15],18) ^ (w[t-15] >> 3)
        s1 = rotr(w[t-2],17) ^ rotr(w[t-2],19) ^ (w[t-2] >> 10)
        w.append((s1+w[t-7]+s0+w[t-16]) & MASK)
    a,b,c,d,e,f,g,h = state
    for t in range(64):
        s1 = rotr(e,6) ^ rotr(e,11) ^ rotr(e,25)
        choose = (e & f) ^ (~e & g)
        t1 = (h+s1+choose+K[t]+w[t]) & MASK
        s0 = rotr(a,2) ^ rotr(a,13) ^ rotr(a,22)
        majority = (a & b) ^ (a & c) ^ (b & c)
        t2 = (s0+majority) & MASK
        a,b,c,d,e,f,g,h = (t1+t2)&MASK,a,b,c,(d+t1)&MASK,e,f,g
    return tuple((x+y)&MASK for x,y in zip(state,(a,b,c,d,e,f,g,h)))


def sha256(message):
    bits = len(message)*8
    padded = message+b'\x80'
    padded += b'\x00'*((56-len(padded))%64)+bits.to_bytes(8,'big')
    state = IV
    for n in range(0,len(padded),64):
        state = compress(padded[n:n+64],state)
    return b''.join(x.to_bytes(4,'big') for x in state)
