a = []
i = 1000
while i > 0
  a << i
  i -= 1
end
p = 0
while p < a.length
  q = 0
  while q < a.length - 1
    if a[q] < a[q + 1]
      tmp = a[q]
      a[q] = a[q + 1]
      a[q + 1] = tmp
    end
    q += 1
  end
  p += 1
end
puts a[0]
puts a[a.length - 1]
