def nested(n)
  total = 0
  for i in 0...n
    for j in 0...n
      for k in 0...n
        total += 1
      end
    end
  end
  total
end

puts nested(60)
