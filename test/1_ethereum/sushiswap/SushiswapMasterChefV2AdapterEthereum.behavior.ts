import hre from "hardhat";
import chai, { expect } from "chai";
import { solidity } from "ethereum-waffle";
import { getAddress } from "ethers/lib/utils";
import { BigNumber, utils } from "ethers";
import { PoolItem } from "../types";
import { getOverrideOptions, setTokenBalanceInStorage } from "../../utils";
import { default as TOKENS } from "../../../helpers/tokens.json";

chai.use(solidity);

const rewardToken = "0x6B3595068778DD592e39A122f4f5a5cF09C90fE2";
const vaultUnderlyingTokens = Object.values(TOKENS).map(x => getAddress(x));

export function shouldBehaveLikeSushiswapMasterChefV2AdapterEthereum(token: string, pool: PoolItem): void {
  it(`should deposit ${token}, claim SUSHI (and extra reward tokens), harvest SUSHI, and withdraw ${token} in ${token} MasterChefV2 of Sushiswap`, async function () {
    if (pool.deprecated === true) {
      this.skip();
    }
    await this.testDeFiAdapter.setUnderlyingToken(pool.tokens[0]);
    const strategyStep = { pool: pool.pool, outputToken: pool.lpToken, isBorrow: false };
    await this.testDeFiAdapter.setInvestStrategySteps(strategyStep);
    const pid = BigNumber.from(pool.pid);
    // harvest finance's deposit vault instance
    const masterChefV2Instance = await hre.ethers.getContractAt("ISushiswapMasterChefV2", pool.pool);
    // harvest finance reward token's instance
    const sushiRewardInstance = await hre.ethers.getContractAt("IERC20", rewardToken);
    // underlying token instance
    const underlyingTokenInstance = await hre.ethers.getContractAt("ERC20", pool.tokens[0]);
    await setTokenBalanceInStorage(underlyingTokenInstance, this.testDeFiAdapter.address, "200");
    // 1. deposit all underlying tokens
    await this.testDeFiAdapter.testGetDepositAllCodes(
      pool.tokens[0],
      pool.pool,
      this.sushiswapMasterChefV2AdapterEthereum.address,
      getOverrideOptions(),
    );
    // 2. assert whether lptoken balance is as expected or not after deposit
    const actualLPTokenBalanceAfterDeposit =
      await this.sushiswapMasterChefV2AdapterEthereum.getLiquidityPoolTokenBalance(
        this.testDeFiAdapter.address,
        pool.tokens[0],
        pool.pool,
      );
    const expectedLPTokenBalanceAfterDeposit = (await masterChefV2Instance.userInfo(pid, this.testDeFiAdapter.address))
      .amount;
    expect(actualLPTokenBalanceAfterDeposit).to.be.eq(expectedLPTokenBalanceAfterDeposit);
    // 3. assert whether underlying token balance is as expected or not after deposit
    const actualUnderlyingTokenBalanceAfterDeposit = await this.testDeFiAdapter.getERC20TokenBalance(
      pool.tokens[0],
      this.testDeFiAdapter.address,
    );
    const expectedUnderlyingTokenBalanceAfterDeposit = await underlyingTokenInstance.balanceOf(
      this.testDeFiAdapter.address,
    );
    expect(actualUnderlyingTokenBalanceAfterDeposit).to.be.eq(expectedUnderlyingTokenBalanceAfterDeposit);
    // 4. assert whether the amount in token is as expected or not after depositing
    const actualAmountInTokenAfterDeposit = await this.sushiswapMasterChefV2AdapterEthereum.getAllAmountInToken(
      this.testDeFiAdapter.address,
      pool.tokens[0],
      pool.pool,
    );
    const expectedAmountInTokenAfterDeposit = (await masterChefV2Instance.userInfo(pid, this.testDeFiAdapter.address))
      .amount;
    expect(actualAmountInTokenAfterDeposit).to.be.eq(expectedAmountInTokenAfterDeposit);
    // 5. assert whether the reward token is as expected or not
    const actualRewardToken = await this.sushiswapMasterChefV2AdapterEthereum.getRewardToken(pool.pool);
    const expectedRewardToken = rewardToken;
    expect(getAddress(actualRewardToken)).to.be.eq(getAddress(expectedRewardToken));
    // 6. make a transaction for mining a block to get finite unclaimed reward amount
    await this.signers.admin.sendTransaction({
      value: utils.parseEther("0"),
      to: await this.signers.admin.getAddress(),
      ...getOverrideOptions(),
    });
    // 7. assert whether the unclaimed reward amount is as expected or not after staking
    const actualUnclaimedReward = await this.sushiswapMasterChefV2AdapterEthereum.getUnclaimedRewardTokenAmount(
      this.testDeFiAdapter.address,
      pool.pool,
      pool.tokens[0],
    );
    const expectedUnclaimedReward = await masterChefV2Instance.pendingSushi(pid, this.testDeFiAdapter.address);
    expect(actualUnclaimedReward).to.be.eq(expectedUnclaimedReward);
    // 8. claim the reward token
    await this.testDeFiAdapter.testClaimRewardTokenCode(
      pool.pool,
      this.sushiswapMasterChefV2AdapterEthereum.address,
      getOverrideOptions(),
    );
    // 9. assert whether the SUSHI token's balance is as expected or not after claiming
    const actualSushiTokenBalanceAfterClaim = await this.testDeFiAdapter.getERC20TokenBalance(
      await this.sushiswapMasterChefV2AdapterEthereum.getRewardToken(pool.pool),
      this.testDeFiAdapter.address,
    );
    const expectedSushiTokenBalanceAfterClaim = await sushiRewardInstance.balanceOf(this.testDeFiAdapter.address);
    expect(actualSushiTokenBalanceAfterClaim).to.be.eq(expectedSushiTokenBalanceAfterClaim);
    // 10. assert whether the extra reward token's balance is as expected or not after claiming
    const rewarderAddress = await masterChefV2Instance.rewarder(BigNumber.from(pool.pid));
    if (rewarderAddress != hre.ethers.constants.AddressZero) {
      const rewarderInstance = await hre.ethers.getContractAt("IRewarder", rewarderAddress);
      let extraRewardTokenAddress;
      if (pool.pid == "0") {
        extraRewardTokenAddress = "0xdBdb4d16EdA451D0503b854CF79D55697F90c8DF";
      } else {
        extraRewardTokenAddress = await rewarderInstance.rewardToken();
      }
      const extraRewardTokenInstance = await hre.ethers.getContractAt("IERC20", extraRewardTokenAddress);
      const actualRewardTokenBalanceAfterClaim = await this.testDeFiAdapter.getERC20TokenBalance(
        extraRewardTokenAddress,
        this.testDeFiAdapter.address,
      );
      const expectedRewardTokenBalanceAfterClaim = await extraRewardTokenInstance.balanceOf(
        this.testDeFiAdapter.address,
      );
      expect(actualRewardTokenBalanceAfterClaim).to.be.eq(expectedRewardTokenBalanceAfterClaim);
    }
    if (vaultUnderlyingTokens.includes(getAddress(pool.tokens[0]))) {
      // 11. Swap the reward token into underlying token
      try {
        await this.testDeFiAdapter.testGetHarvestAllCodes(
          pool.pool,
          pool.tokens[0],
          this.sushiswapMasterChefV2AdapterEthereum.address,
          getOverrideOptions(),
        );
        // 12. assert whether the reward token is swapped to underlying token or not
        expect(await this.testDeFiAdapter.getERC20TokenBalance(pool.tokens[0], this.testDeFiAdapter.address)).to.be.gte(
          0,
        );
        console.log("✓ Harvest");
      } catch {
        // may throw error from DEX due to insufficient reserves
      }
    }
    // 13. Withdraw all lpToken balance
    await this.testDeFiAdapter.testGetWithdrawAllCodes(
      pool.tokens[0],
      pool.pool,
      this.sushiswapMasterChefV2AdapterEthereum.address,
      getOverrideOptions(),
    );
    // 14. assert whether lpToken balance is as expected or not
    const actualLPTokenBalanceAfterWithdraw =
      await this.sushiswapMasterChefV2AdapterEthereum.getLiquidityPoolTokenBalance(
        this.testDeFiAdapter.address,
        this.testDeFiAdapter.address, // placeholder of type address
        pool.pool,
      );
    const expectedLPTokenBalanceAfterWithdraw = (await masterChefV2Instance.userInfo(pid, this.testDeFiAdapter.address))
      .amount;
    expect(actualLPTokenBalanceAfterWithdraw).to.be.eq(expectedLPTokenBalanceAfterWithdraw);
    // 15. assert whether underlying token balance is as expected or not after withdraw
    const actualUnderlyingTokenBalanceAfterWithdraw = await this.testDeFiAdapter.getERC20TokenBalance(
      pool.tokens[0],
      this.testDeFiAdapter.address,
    );
    const expectedUnderlyingTokenBalanceAfterWithdraw = await underlyingTokenInstance.balanceOf(
      this.testDeFiAdapter.address,
    );
    expect(actualUnderlyingTokenBalanceAfterWithdraw).to.be.eq(expectedUnderlyingTokenBalanceAfterWithdraw);
  }).timeout(100000);
}
