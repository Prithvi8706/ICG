"""Differential test: random programs through icg and twopass."""
import random, subprocess, sys, os, tempfile
ICG, TWO, N, SEED = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
rnd = random.Random(SEED)
V = list("abcdefghijk")
def E(d):
    if d <= 0 or rnd.random() < .35:
        return rnd.choice(V + [str(rnd.randint(0, 99))])
    k = rnd.random()
    if k < .1: return "-" + E(d-1)
    if k < .2: return "(" + E(d-1) + ")"
    return E(d-1) + " " + rnd.choice("+-*/") + " " + E(d-1)
def B(d):
    k = rnd.random()
    if d <= 0 or k < .4: return E(1) + " " + rnd.choice(["<","<=",">",">=","==","!="]) + " " + E(1)
    if k < .5: return rnd.choice(["true", "false"])
    if k < .6: return "!" + "(" + B(d-1) + ")"
    if k < .7: return "(" + B(d-1) + ")"
    return B(d-1) + rnd.choice([" && ", " || "]) + B(d-1)
def A(): return rnd.choice(V) + " = " + E(2)
def S(d, loop):
    k = rnd.random()
    if d <= 0 or k < .3: 
        if loop and k < .08: return rnd.choice(["break;", "continue;"])
        return A() + ";"
    if k < .45: return "if (" + B(2) + ") " + S(d-1, loop)
    if k < .58: return "if (" + B(2) + ") " + S(d-1, loop) + " else " + S(d-1, loop)
    if k < .7: return "while (" + B(2) + ") " + S(d-1, True)
    if k < .8: return "do " + S(d-1, True) + " while (" + B(2) + ");"
    if k < .9: return "for (" + A() + "; " + B(2) + "; " + A() + ") " + S(d-1, True)
    return "{ " + " ".join(S(d-1, loop) for _ in range(rnd.randint(1, 3))) + " }"
same = unfilled = quads = 0; maxq = 0
d = tempfile.mkdtemp()
for i in range(N):
    p = "\n".join(S(4, False) for _ in range(rnd.randint(1, 5))) + "\n"
    f = os.path.join(d, "p.src"); open(f, "w").write(p)
    a = subprocess.run([ICG, f], capture_output=True, text=True)
    b = subprocess.run([TWO, f], capture_output=True, text=True)
    t = subprocess.run([ICG, "--trace", f], capture_output=True, text=True)
    if a.stdout + a.stderr == b.stdout + b.stderr and a.returncode == b.returncode \
       and t.stdout.endswith(a.stdout): same += 1
    else:
        open(os.path.join(d, "fail%d.src" % i), "w").write(p); print("MISMATCH", i)
    if "goto _" in a.stdout: unfilled += 1
    n = a.stdout.count("\n"); quads += n; maxq = max(maxq, n)
print(f"programs generated      : {N}  (seed {SEED})")
print(f"identical icg / twopass : {same}")
print(f"left a 'goto _'         : {unfilled}")
print(f"quadruples generated    : {quads}  (largest program {maxq})")
