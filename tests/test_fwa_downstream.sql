-- Crude tests, all should return true

-- watershed code comparisons
SELECT FWA_downstream(
  '100.100000.000100'::ltree,
  '100.100000.000100'::ltree,
  '100.100000'::ltree,
  '100.100000'::ltree
) as result;

SELECT FWA_downstream(
  '100.100000'::ltree,
  '100.100000'::ltree,
  '100.100000.000100'::ltree,
  '100.100000.000100'::ltree
) = false as result;

SELECT FWA_downstream(
  '930.079351.500724'::ltree,
  '930.079351.500724'::ltree,
  '930.079351'::ltree,
  '930.079351.290329'::ltree
) as result;

SELECT FWA_downstream(
  '930.079351.290329'::ltree,
  '930.079351.290329'::ltree,
  '930.079351'::ltree,
  '930.079351.290329'::ltree
) = false as result;

-- watershed code and meausre comparisons
SELECT fwa_downstream(
    354133645,
    150,
    '930.079351'::ltree,
    '930.079351'::ltree,
    354133645,
    100,
    '930.079351'::ltree,
    '930.079351'::ltree
) as result;

SELECT fwa_downstream(
    354133645,
    75,
    '930.079351'::ltree,
    '930.079351'::ltree,
    354133645,
    100,
    '930.079351'::ltree,
    '930.079351'::ltree
) = false as result;

SELECT fwa_downstream(
    354133645,
    1900,
    '930.079351'::ltree,
    '930.079351.500724'::ltree,
    354133645,
    100,
    '930.079351'::ltree,
    '930.079351'::ltree
) as result;

SELECT fwa_downstream(
    354131334,
    50,
    '930.079351.500724'::ltree,
    '930.079351.500724'::ltree,
    354133645,
    100,
    '930.079351'::ltree,
    '930.079351'::ltree
) as result;

SELECT fwa_downstream(
    354131334,
    50,
    '930.079351.500724'::ltree,
    '930.079351.500724'::ltree,
    354133645,
    1900,
    '930.079351'::ltree,
    '930.079351.500724'::ltree
) is false as result;

-- tolerance is less than distance between measures, result is true
SELECT fwa_downstream(
    354133645,
    101,
    '930.079351'::ltree,
    '930.079351'::ltree,
    354133645,
    100,
    '930.079351'::ltree,
    '930.079351'::ltree,
    .1
) as result;

-- tolerance is greater than distance between measures, result is false
SELECT fwa_downstream(
    354133645,
    101,
    '930.079351'::ltree,
    '930.079351'::ltree,
    354133645,
    100,
    '930.079351'::ltree,
    '930.079351'::ltree,
    2
) is false as result;