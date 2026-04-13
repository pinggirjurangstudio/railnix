{
  environments.development = {
    domains.main = "frontend-dev.example.com";
  };
  environments.production = {
    domains.main = "frontend.example.com";
    domains.apex = "example.com";
    domains.www = "www.example.com";
  };
}
