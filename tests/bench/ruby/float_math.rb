def accumulate(n)
  x = 1.0
  i = 0
  while i < n
    x = x * 1.000001 + 0.5
    i += 1
  end
  x
end

puts accumulate(2000000)
