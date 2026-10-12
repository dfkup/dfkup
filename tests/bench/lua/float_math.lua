function accumulate(n)
    local x = 1.0
    for i = 1, n do x = x * 1.000001 + 0.5 end
    return x
end
print(accumulate(2000000))
