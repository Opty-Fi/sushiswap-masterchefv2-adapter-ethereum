import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/dist/src/signer-with-address";
import { Fixture } from "ethereum-waffle";
import { SushiswapMasterChefV2AdapterEthereum, OptyFiOracle } from "../../typechain";
import { IUniswapV2Router02 } from "../../typechain/IUniswapV2Router02";
import { TestDeFiAdapter } from "../../typechain/TestDeFiAdapter";

export interface Signers {
  admin: SignerWithAddress;
  owner: SignerWithAddress;
  deployer: SignerWithAddress;
  alice: SignerWithAddress;
  operator: SignerWithAddress;
}

export interface PoolItem {
  pool: string;
  lpToken: string;
  stakingVault?: string;
  rewardTokens?: string[];
  tokens: string[];
  swap?: string;
  deprecated?: boolean;
  pid?: string;
}

export interface LiquidityPool {
  [name: string]: PoolItem;
}

declare module "mocha" {
  export interface Context {
    sushiswapMasterChefV2AdapterEthereum: SushiswapMasterChefV2AdapterEthereum;
    testDeFiAdapter: TestDeFiAdapter;
    optyFiOracle: OptyFiOracle;
    sushiswapRouter: IUniswapV2Router02;
    loadFixture: <T>(fixture: Fixture<T>) => Promise<T>;
    signers: Signers;
  }
}
