def concat(n)
  s = ""
  for i in 0...n
    s << "x"
  end
  s.length
end

puts concat(10000)
