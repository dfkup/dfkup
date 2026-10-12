def fizzbuzz(n):
    fizz = buzz = both = plain = 0
    i = 1
    while i <= n:
        if i % 3 == 0:
            if i % 5 == 0:
                both += 1
            else:
                fizz += 1
        elif i % 5 == 0:
            buzz += 1
        else:
            plain += 1
        i += 1
    return fizz + buzz + both + plain

print(fizzbuzz(20000000))
