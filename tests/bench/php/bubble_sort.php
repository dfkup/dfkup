<?php
$a = [];
for ($i = 1000; $i > 0; $i--) $a[] = $i;
for ($p = 0; $p < count($a); $p++) {
    for ($q = 0; $q < count($a) - 1; $q++) {
        if ($a[$q] < $a[$q + 1]) {
            $tmp = $a[$q];
            $a[$q] = $a[$q + 1];
            $a[$q + 1] = $tmp;
        }
    }
}
echo $a[0] . "\n";
echo $a[count($a) - 1] . "\n";
