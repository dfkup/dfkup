def concat(n):
    s = ""
    for i in range(n):
        s += "x"
    return len(s)

print(concat(10000))
