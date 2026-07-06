function nested(n) {
    let total = 0;
    for (let i = 0; i < n; i++)
        for (let j = 0; j < n; j++)
            for (let k = 0; k < n; k++)
                total++;
    return total;
}
console.log(nested(60));
