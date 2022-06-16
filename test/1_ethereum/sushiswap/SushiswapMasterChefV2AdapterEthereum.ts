import hre from "hardhat";
import { Artifact } from "hardhat/types";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import SushiswapMasterChefV2EthereumPools from "../../../helpers/poolsV2.json";
import { SushiswapMasterChefV2AdapterEthereum } from "../../../typechain/SushiswapMasterChefV2AdapterEthereum";
import { TestDeFiAdapter } from "../../../typechain/TestDeFiAdapter";
import { LiquidityPool, Signers } from "../types";
import { shouldBehaveLikeSushiswapMasterChefV2AdapterEthereum } from "./SushiswapMasterChefV2AdapterEthereum.behavior";
import { IUniswapV2Router02 } from "../../../typechain";
import { getOverrideOptions } from "../../utils";

const { deployContract } = hre.waffle;

describe("Unit tests", function () {
  before(async function () {
    this.signers = {} as Signers;
    const signers: SignerWithAddress[] = await hre.ethers.getSigners();
    this.signers.admin = signers[0];
    this.signers.owner = signers[1];
    this.signers.deployer = signers[2];
    this.signers.alice = signers[3];
    this.signers.operator = await hre.ethers.getSigner("0x6bd60f089B6E8BA75c409a54CDea34AA511277f6");

    // get the UniswapV2Router contract instance
    this.sushiswapRouter = <IUniswapV2Router02>(
      await hre.ethers.getContractAt("IUniswapV2Router02", "0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F")
    );

    // deploy Harvest Finance Adapter
    const sushiswapMasterChefV2AdapterEthereumArtifact: Artifact = await hre.artifacts.readArtifact(
      "SushiswapMasterChefV2AdapterEthereum",
    );
    this.sushiswapMasterChefV2AdapterEthereum = <SushiswapMasterChefV2AdapterEthereum>(
      await deployContract(
        this.signers.deployer,
        sushiswapMasterChefV2AdapterEthereumArtifact,
        ["0x99fa011e33a8c6196869dec7bc407e896ba67fe3"],
        getOverrideOptions(),
      )
    );

    // deploy TestDeFiAdapter Contract
    const testDeFiAdapterArtifact: Artifact = await hre.artifacts.readArtifact("TestDeFiAdapter");
    this.testDeFiAdapter = <TestDeFiAdapter>(
      await deployContract(this.signers.deployer, testDeFiAdapterArtifact, [], getOverrideOptions())
    );
  });

  describe("SushiswapMasterChefV2AdapterEthereum", function () {
    Object.keys(SushiswapMasterChefV2EthereumPools).map((token: string) => {
      shouldBehaveLikeSushiswapMasterChefV2AdapterEthereum(
        token,
        (SushiswapMasterChefV2EthereumPools as LiquidityPool)[token],
      );
    });
  });
});
