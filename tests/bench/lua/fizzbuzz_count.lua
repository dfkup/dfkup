function fizzbuzz(n)
    local fizz, buzz, both, plain = 0, 0, 0, 0
    for i = 1, n do
        if i % 3 == 0 then
            if i % 5 == 0 then both = both + 1
            else fizz = fizz + 1 end
        elseif i % 5 == 0 then buzz = buzz + 1
        else plain = plain + 1 end
    end
    return fizz + buzz + both + plain
end
print(fizzbuzz(20000000))
