a = []
i = 0
while i < 200000
  a << i
  i += 1
end
total = 0
j = 0
while j < a.length
  total += a[j]
  j += 1
end
puts total
