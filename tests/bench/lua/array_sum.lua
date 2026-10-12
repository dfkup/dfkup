local a = {}
for i = 0, 199999 do a[#a + 1] = i end
local total = 0
for j = 1, #a do total = total + a[j] end
print(total)
