def is_even(x):
    return x - (x // 2) * 2 == 0

def collatz_len(n):
    x = n
    length = 0
    while x > 1:
        x = x // 2 if is_even(x) else x * 3 + 1
        length += 1
    return length

total = 0
i = 1
while i <= 100000:
    total += collatz_len(i)
    i += 1
print(total)
