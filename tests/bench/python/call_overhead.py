def bump(x):
    return x + 1

def hammer(n):
    total = 0
    i = 0
    while i < n:
        total = bump(total)
        i += 1
    return total

print(hammer(500000))
