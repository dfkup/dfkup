def is_even(x)
  x - (x / 2) * 2 == 0
end

def collatz_len(n)
  x = n
  len = 0
  while x > 1
    if is_even(x)
      x = x / 2
    else
      x = x * 3 + 1
    end
    len += 1
  end
  len
end

total = 0
i = 1
while i <= 100000
  total += collatz_len(i)
  i += 1
end
puts total
