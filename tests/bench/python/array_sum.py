a = []
i = 0
while i < 200000:
    a.append(i)
    i += 1
total = 0
j = 0
while j < len(a):
    total += a[j]
    j += 1
print(total)
