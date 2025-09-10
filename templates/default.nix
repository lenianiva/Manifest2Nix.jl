rec {
  minimal = {
    path = ./minimal;
    description = "Minimal Project with no dependencies";
  };
  simple = {
    path = ./simple;
    description = "Simple Project with one dependency";
  };
  default = simple;
}
