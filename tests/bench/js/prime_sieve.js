function sieve(n) {
    let count = 0;
    for (let i = 2; i < n; i++) {
        let isPrime = true;
        for (let j = 2; j * j <= i; j++) {
            if (i % j === 0) { isPrime = false; break; }
        }
        if (isPrime) count++;
    }
    return count;
}
console.log(sieve(5000));
