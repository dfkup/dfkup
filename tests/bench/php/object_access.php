<?php
function churn($n) {
    $p = ["x" => 0, "y" => 0];
    $cycles = 0;
    for ($i = 0; $i < $n; $i++) {
        $p["x"] = $p["x"] + 1;
        $p["y"] = $p["y"] + $p["x"];
        if ($p["x"] == 1000) {
            $p["x"] = 0;
            $p["y"] = 0;
            $cycles++;
        }
    }
    return $cycles;
}
echo churn(1000000) . "\n";
