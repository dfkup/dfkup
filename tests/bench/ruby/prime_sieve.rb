def sieve(n)
  count = 0
  for i in 2...n
    is_prime = true
    j = 2
    while j * j <= i
      if i % j == 0
        is_prime = false
        break
      end
      j += 1
    end
    count += 1 if is_prime
  end
  count
end

puts sieve(5000)
