<?php
$a = [];
for ($i = 0; $i < 200000; $i++) $a[] = $i;
$total = 0;
for ($j = 0; $j < count($a); $j++) $total += $a[$j];
echo $total . "\n";
