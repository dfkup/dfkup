def churn(n):
    p = {"x": 0, "y": 0}
    cycles = 0
    i = 0
    while i < n:
        p["x"] += 1
        p["y"] += p["x"]
        if p["x"] == 1000:
            p["x"] = 0
            p["y"] = 0
            cycles += 1
        i += 1
    return cycles

print(churn(1000000))
