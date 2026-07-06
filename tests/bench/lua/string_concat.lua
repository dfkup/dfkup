function concat(n)
    local s = ""
    for i = 1, n do
        s = s .. "x"
    end
    return #s
end
print(concat(10000))
