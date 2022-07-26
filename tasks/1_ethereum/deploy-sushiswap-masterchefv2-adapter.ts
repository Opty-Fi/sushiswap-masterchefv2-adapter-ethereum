import { task } from "hardhat/config";
import { TaskArguments } from "hardhat/types";

import {
  SushiswapMasterChefV2AdapterEthereum,
  SushiswapMasterChefV2AdapterEthereum__factory,
} from "../../../typechain";

task("deploy-sushiswap-masterchefv2-adapter").setAction(async function (taskArguments: TaskArguments, { ethers }) {
  const sushiswapMasterChefV2AdapterEthereumFactory: SushiswapMasterChefV2AdapterEthereum__factory =
    await ethers.getContractFactory("SushiswapMasterChefV2AdapterEthereum");
  const sushiswapMasterChefV2AdapterEthereum: SushiswapMasterChefV2AdapterEthereum = <
    SushiswapMasterChefV2AdapterEthereum
  >await sushiswapMasterChefV2AdapterEthereumFactory.deploy(taskArguments[0], taskArguments[1]);
  await sushiswapMasterChefV2AdapterEthereum.deployed();
  console.log("SushiswapMasterChefV2AdapterEthereum deployed to: ", sushiswapMasterChefV2AdapterEthereum.address);
});
