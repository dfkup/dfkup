local a = {}
for i = 1000, 1, -1 do a[#a + 1] = i end
for p = 1, #a do
    for q = 1, #a - 1 do
        if a[q] < a[q + 1] then
            local tmp = a[q]
            a[q] = a[q + 1]
            a[q + 1] = tmp
        end
    end
end
print(a[1])
print(a[#a])
