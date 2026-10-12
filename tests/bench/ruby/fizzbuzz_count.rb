def fizzbuzz(n)
  fizz = buzz = both = plain = 0
  i = 1
  while i <= n
    if i % 3 == 0
      if i % 5 == 0
        both += 1
      else
        fizz += 1
      end
    elsif i % 5 == 0
      buzz += 1
    else
      plain += 1
    end
    i += 1
  end
  fizz + buzz + both + plain
end

puts fizzbuzz(20000000)
