function is_even(x) return x - math.floor(x / 2) * 2 == 0 end
function collatz_len(n)
    local x = n
    local len = 0
    while x > 1 do
        if is_even(x) then x = x / 2
        else x = x * 3 + 1 end
        len = len + 1
    end
    return len
end
local total = 0
for i = 1, 100000 do total = total + collatz_len(i) end
print(total)
