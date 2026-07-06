function nested(n)
    local total = 0
    for i = 1, n do
        for j = 1, n do
            for k = 1, n do
                total = total + 1
            end
        end
    end
    return total
end
print(nested(60))
