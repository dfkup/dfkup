<?php
function fizzbuzz($n) {
    $fizz = $buzz = $both = $plain = 0;
    for ($i = 1; $i <= $n; $i++) {
        if ($i % 3 == 0) {
            if ($i % 5 == 0) $both++;
            else $fizz++;
        } elseif ($i % 5 == 0) $buzz++;
        else $plain++;
    }
    return $fizz + $buzz + $both + $plain;
}
echo fizzbuzz(20000000) . "\n";
