function bump(x) { return x + 1; }
function hammer(n) {
    let total = 0;
    for (let i = 0; i < n; i++) total = bump(total);
    return total;
}
console.log(hammer(500000));
