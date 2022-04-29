const minCommitmentAge = 1;
const maxCommitmentAge = 1000;
const costPerYear = 1;
const maxYear = 5;
const url = "url";
const waitPeriod = 10;

async function main() {
    const [deployer] = await ethers.getSigners();
  
    console.log("Deploying contracts with the account:", deployer.address);
  
    console.log("Account balance:", (await deployer.getBalance()).toString());
  
    const Register = await ethers.getContractFactory("Register");
    const register = await Register.deploy(minCommitmentAge, maxCommitmentAge, costPerYear, maxYear, url, waitPeriod);
  
    console.log("Register address:", register.address);
  }
  
  main()
    .then(() => process.exit(0))
    .catch((error) => {
      console.error(error);
      process.exit(1);
    });