function fizzbuzz(n) {
    let fizz = 0, buzz = 0, both = 0, plain = 0;
    for (let i = 1; i <= n; i++) {
        if (i % 3 === 0) {
            if (i % 5 === 0) both++;
            else fizz++;
        } else if (i % 5 === 0) buzz++;
        else plain++;
    }
    return fizz + buzz + both + plain;
}
console.log(fizzbuzz(20000000));
