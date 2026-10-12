function accumulate(n) {
    let x = 1.0;
    for (let i = 0; i < n; i++) x = x * 1.000001 + 0.5;
    return x;
}
console.log(accumulate(2000000));
