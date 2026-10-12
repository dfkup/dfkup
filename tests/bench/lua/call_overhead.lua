function bump(x) return x + 1 end
function hammer(n)
    local total = 0
    for i = 1, n do total = bump(total) end
    return total
end
print(hammer(500000))
