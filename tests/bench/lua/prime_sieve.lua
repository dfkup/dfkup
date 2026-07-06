function sieve(n)
    local count = 0
    for i = 2, n - 1 do
        local is_prime = true
        local j = 2
        while j * j <= i do
            if i % j == 0 then
                is_prime = false
                break
            end
            j = j + 1
        end
        if is_prime then count = count + 1 end
    end
    return count
end
print(sieve(5000))
