a = []
i = 1000
while i > 0:
    a.append(i)
    i -= 1
p = 0
while p < len(a):
    q = 0
    while q < len(a) - 1:
        if a[q] < a[q + 1]:
            tmp = a[q]
            a[q] = a[q + 1]
            a[q + 1] = tmp
        q += 1
    p += 1
print(a[0])
print(a[len(a) - 1])
