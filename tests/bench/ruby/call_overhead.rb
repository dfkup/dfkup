def bump(x)
  x + 1
end

def hammer(n)
  total = 0
  i = 0
  while i < n
    total = bump(total)
    i += 1
  end
  total
end

puts hammer(500000)
