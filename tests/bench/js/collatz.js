function isEven(x) { return x - Math.floor(x / 2) * 2 === 0; }
function collatzLen(n) {
    let x = n, len = 0;
    while (x > 1) {
        x = isEven(x) ? x / 2 : x * 3 + 1;
        len++;
    }
    return len;
}
let total = 0;
for (let i = 1; i <= 100000; i++) total += collatzLen(i);
console.log(total);
