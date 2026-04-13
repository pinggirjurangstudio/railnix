{
  dependencies = [ ../shared ];
  deploy = {
    healthcheckPath = "/health";
    healthcheckTimeout = 300;
  };
  environments.development = {
    domains.main = "backend-dev.example.com";
  };
}
