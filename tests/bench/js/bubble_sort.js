let a = [];
for (let i = 1000; i > 0; i--) a.push(i);
for (let p = 0; p < a.length; p++) {
    for (let q = 0; q < a.length - 1; q++) {
        if (a[q] < a[q + 1]) {
            const tmp = a[q];
            a[q] = a[q + 1];
            a[q + 1] = tmp;
        }
    }
}
console.log(a[0]);
console.log(a[a.length - 1]);
