# Sample Hardhat Project

This project demonstrates a basic Hardhat use case. It comes with a sample contract, a test for that contract, and a Hardhat Ignition module that deploys that contract.

Try running some of the following tasks:

```shell
npx hardhat help
npx hardhat test
REPORT_GAS=true npx hardhat test
npx hardhat node
npx hardhat ignition deploy ./ignition/modules/Lock.js
```

### 
Create a .env file and copy the keys from the .envExample file. Paste these keys into the .env file and provide their corresponding values.

<!-- For dev -->
### contract deployment and vefication
```npx hardhat ignition deploy ignition/modules/NCI.js --network bscTestnet --verify```

### contract deployment 
```npx hardhat ignition deploy ignition/modules/NCI.js --network bscTestnet```

### contract verfication
After deploying the contract with hardhat, please verify the contract on tesntet using the testnet API key stored in the .env file

```npx hardhat ignition verify chain-97 --include-unrelated-contracts```

<!-- For Prod -->
### contract deployment and vefication
```npx hardhat ignition deploy ignition/modules/NCI.js --network mainnet --verify```

### contract deployment 
```npx hardhat ignition deploy ignition/modules/NCI.js --network mainnet ```

### contract verfication
After deploying the contract with hardhat, please verify the contract on Etherscan using the Etherscan API key stored in the .env file
```npx hardhat ignition verify chain-1 --include-unrelated-contracts```


