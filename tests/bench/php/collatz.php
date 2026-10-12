<?php
function is_even($x) { return $x - (int)($x / 2) * 2 == 0; }
function collatz_len($n) {
    $x = $n;
    $len = 0;
    while ($x > 1) {
        if (is_even($x)) $x = $x / 2;
        else $x = $x * 3 + 1;
        $len++;
    }
    return $len;
}
$total = 0;
for ($i = 1; $i <= 100000; $i++) $total += collatz_len($i);
echo $total . "\n";
