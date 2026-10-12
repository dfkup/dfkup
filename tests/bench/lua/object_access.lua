function churn(n)
    local p = {x = 0, y = 0}
    local cycles = 0
    for i = 1, n do
        p.x = p.x + 1
        p.y = p.y + p.x
        if p.x == 1000 then
            p.x = 0
            p.y = 0
            cycles = cycles + 1
        end
    end
    return cycles
end
print(churn(1000000))
