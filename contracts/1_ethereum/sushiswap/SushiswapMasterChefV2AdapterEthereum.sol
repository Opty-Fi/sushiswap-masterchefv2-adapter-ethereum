// SPDX-License-Identifier:MIT

pragma solidity =0.8.11;

// libraries
import { Address } from "@openzeppelin/contracts-0.8.x/utils/Address.sol";

// helpers
import { AdapterModifiersBase } from "../../utils/AdapterModifiersBase.sol";

// interfaces
import { ISushiswapMasterChefV2 } from "@optyfi/defi-legos/ethereum/sushiswap/contracts/ISushiswapMasterChefV2.sol";
import { IERC20 } from "@openzeppelin/contracts-0.8.x/token/ERC20/IERC20.sol";
import { IAdapter } from "@optyfi/defi-legos/interfaces/defiAdapters/contracts/IAdapter.sol";
import { IAdapterHarvestReward } from "@optyfi/defi-legos/interfaces/defiAdapters/contracts/IAdapterHarvestReward.sol";
import "@optyfi/defi-legos/interfaces/defiAdapters/contracts/IAdapterInvestLimit.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";

import "hardhat/console.sol";

interface IVault {
    /**
     * @notice Container for Strategy Steps used by Strategy
     * @param pool Liquidity Pool address
     * @param outputToken Output token of the liquidity pool
     * @param isBorrow If borrow is allowed or not for the liquidity pool
     */
    struct StrategyStep {
        address pool;
        address outputToken;
        bool isBorrow;
    }

    function underlyingToken() external view returns (address);

    /**
     * @notice retrieves current strategy metadata
     * @return array of strategy steps
     */
    function getInvestStrategySteps() external view returns (StrategyStep[] memory);
}

/**
 * @title Adapter for Sushiswap protocol
 * @author Opty.fi
 * @dev Abstraction layer to Sushiswap's MasterChef contract
 */

contract SushiswapMasterChefV2AdapterEthereum is
    IAdapter,
    IAdapterInvestLimit,
    IAdapterHarvestReward,
    AdapterModifiersBase
{
    using Address for address;

    /** @notice max deposit value datatypes */
    MaxExposure public maxDepositProtocolMode;

    /** @notice Sushiswap router contract address */
    address public constant SUSHISWAP_ROUTER = address(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);

    /** @notice max deposit's protocol value in percentage */
    uint256 public maxDepositProtocolPct; // basis points

    /** @notice Maps liquidityPool to max deposit value in percentage */
    mapping(address => uint256) public maxDepositPoolPct; // basis points

    /** @notice Maps liquidityPool to max deposit value in absolute value for a specific token */
    mapping(address => mapping(address => uint256)) public maxDepositAmount;

    /** @notice Maps underlyingToken to the ID of its pool */
    mapping(address => uint256) public underlyingTokenToPid;

    /** @notice List of Sushiswap pairs */
    address public constant WETH_ALCX = address(0xC3f279090a47e80990Fe3a9c30d24Cb117EF91a8);
    address public constant YGG_WETH = address(0x99B42F2B49C395D2a77D973f6009aBb5d67dA343);
    address public constant WETH_ENS = address(0xa1181481bEb2dc5De0DaF2c85392d81C704BF75D);
    address public constant WETH_IMX = address(0x18Cd890F4e23422DC4aa8C2D6E0Bd3F3bD8873d8);
    address public constant WETH_JPEG = address(0xdB06a76733528761Eda47d356647297bC35a98BD);
    address public constant APE_USDT = address(0xB27C7b131Cf4915BeC6c4Bc1ce2F33f9EE434b9f);

    constructor(address _registry) AdapterModifiersBase(_registry) {
        maxDepositProtocolPct = uint256(10000); // 100% (basis points)
        maxDepositProtocolMode = MaxExposure.Pct;
        underlyingTokenToPid[YGG_WETH] = uint256(6);
        underlyingTokenToPid[WETH_ENS] = uint256(24);
        underlyingTokenToPid[WETH_IMX] = uint256(27);
        underlyingTokenToPid[WETH_JPEG] = uint256(54);
        underlyingTokenToPid[APE_USDT] = uint256(55);
    }

    /**
     * @inheritdoc IAdapterInvestLimit
     */
    function setMaxDepositPoolPct(address _underlyingToken, uint256 _maxDepositPoolPct)
        external
        override
        onlyRiskOperator
    {
        maxDepositPoolPct[_underlyingToken] = _maxDepositPoolPct;
        emit LogMaxDepositPoolPct(maxDepositPoolPct[_underlyingToken], msg.sender);
    }

    /**
     * @inheritdoc IAdapterInvestLimit
     */
    function setMaxDepositAmount(
        address _masterChef,
        address _underlyingToken,
        uint256 _maxDepositAmount
    ) external override onlyRiskOperator {
        maxDepositAmount[_masterChef][_underlyingToken] = _maxDepositAmount;
        emit LogMaxDepositAmount(maxDepositAmount[_masterChef][_underlyingToken], msg.sender);
    }

    /**
     * @inheritdoc IAdapter
     */
    function getDepositAllCodes(
        address payable _vault,
        address _underlyingToken,
        address _masterChef
    ) external view override returns (bytes[] memory) {
        return getDepositSomeCodes(_vault, _underlyingToken, _masterChef, IERC20(_underlyingToken).balanceOf(_vault));
    }

    /**
     * @inheritdoc IAdapter
     */
    function getWithdrawAllCodes(
        address payable _vault,
        address _underlyingToken,
        address _masterChef
    ) external view override returns (bytes[] memory) {
        return
            getWithdrawSomeCodes(
                _vault,
                _underlyingToken,
                _masterChef,
                getLiquidityPoolTokenBalance(_vault, _underlyingToken, _masterChef)
            );
    }

    /**
     * @inheritdoc IAdapter
     */
    function getUnderlyingTokens(address, address) external pure override returns (address[] memory) {
        revert("!empty");
    }

    /**
     * @inheritdoc IAdapter
     */
    function getSomeAmountInToken(
        address,
        address,
        uint256 _amount
    ) external pure override returns (uint256) {
        return _amount;
    }

    /**
     * @inheritdoc IAdapter
     */
    function calculateAmountInLPToken(
        address,
        address,
        uint256 _amount
    ) external pure override returns (uint256) {
        return _amount;
    }

    /**
     * @inheritdoc IAdapter
     */
    function calculateRedeemableLPTokenAmount(
        address payable _vault,
        address _underlyingToken,
        address _masterChef,
        uint256
    ) external view override returns (uint256 _amount) {
        (_amount, ) = ISushiswapMasterChefV2(_masterChef).userInfo(underlyingTokenToPid[_underlyingToken], _vault);
    }

    /**
     * @inheritdoc IAdapter
     */
    function isRedeemableAmountSufficient(
        address payable _vault,
        address _underlyingToken,
        address _masterChef,
        uint256 _redeemAmount
    ) external view override returns (bool) {
        return getAllAmountInToken(_vault, _underlyingToken, _masterChef) >= _redeemAmount;
    }

    /**
     * @inheritdoc IAdapterHarvestReward
     */
    function getClaimRewardTokenCode(address payable _vault, address _masterChef)
        external
        view
        override
        returns (bytes[] memory _codes)
    {
        IVault.StrategyStep[] memory _investStrategySteps = IVault(_vault).getInvestStrategySteps();
        uint256 _nSteps = _investStrategySteps.length;
        address _vaultUT = IVault(_vault).underlyingToken();
        uint256 _pid;
        if (_vaultUT == WETH_ALCX) {
            _pid = uint256(0);
        } else if (underlyingTokenToPid[_vaultUT] != uint256(0)) {
            _pid = underlyingTokenToPid[_vaultUT];
        } else {
            for (uint256 i = 0; i < _nSteps; i++) {
                address _outputToken = _investStrategySteps[i].outputToken;
                if (_outputToken == WETH_ALCX) {
                    _pid = uint256(0);
                } else if (underlyingTokenToPid[_outputToken] != uint256(0)) {
                    _pid = underlyingTokenToPid[_outputToken];
                }
            }
        }
        _codes = new bytes[](1);
        _codes[0] = abi.encode(_masterChef, abi.encodeWithSignature("harvest(uint256,address)", _pid, _vault));
    }

    /**
     * @inheritdoc IAdapterHarvestReward
     */
    function getHarvestAllCodes(
        address payable _vault,
        address _underlyingToken,
        address _masterChef
    ) external view override returns (bytes[] memory) {
        return
            getHarvestSomeCodes(
                _vault,
                _underlyingToken,
                _masterChef,
                IERC20(getRewardToken(_masterChef)).balanceOf(_vault)
            );
    }

    /**
     * @inheritdoc IAdapter
     */
    function canStake(address) external pure override returns (bool) {
        return false;
    }

    /**
     * @notice Map underlyingToken to its pool ID
     * @param _underlyingTokens pair contract addresses to be mapped with pool ID
     * @param _pids pool IDs to be linked with pair address
     */
    function setUnderlyingTokenToPid(address[] memory _underlyingTokens, uint256[] memory _pids) public onlyOperator {
        uint256 _underlyingTokensLen = _underlyingTokens.length;
        uint256 _pidsLen = _pids.length;
        require(_underlyingTokensLen == _pidsLen, "inequal length of underlyingtokens and pids");
        for (uint256 _i; _i < _underlyingTokensLen; _i++) {
            underlyingTokenToPid[_underlyingTokens[_i]] = _pids[_i];
        }
    }

    /**
     * @inheritdoc IAdapterInvestLimit
     */
    function setMaxDepositProtocolMode(MaxExposure _mode) external override onlyRiskOperator {
        maxDepositProtocolMode = _mode;
        emit LogMaxDepositProtocolMode(maxDepositProtocolMode, msg.sender);
    }

    /**
     * @inheritdoc IAdapterInvestLimit
     */
    function setMaxDepositProtocolPct(uint256 _maxDepositProtocolPct) external override onlyRiskOperator {
        maxDepositProtocolPct = _maxDepositProtocolPct;
        emit LogMaxDepositProtocolPct(maxDepositProtocolPct, msg.sender);
    }

    /**
     * @inheritdoc IAdapter
     */
    function getDepositSomeCodes(
        address payable _vault,
        address _underlyingToken,
        address _masterChef,
        uint256 _amount
    ) public view override returns (bytes[] memory _codes) {
        uint256 _depositAmount = _getDepositAmount(_masterChef, _underlyingToken, _amount);
        if (_depositAmount > 0) {
            _codes = new bytes[](3);
            _codes[0] = abi.encode(
                _underlyingToken,
                abi.encodeWithSignature("approve(address,uint256)", _masterChef, uint256(0))
            );
            _codes[1] = abi.encode(
                _underlyingToken,
                abi.encodeWithSignature("approve(address,uint256)", _masterChef, _depositAmount)
            );
            _codes[2] = abi.encode(
                _masterChef,
                abi.encodeWithSignature(
                    "deposit(uint256,uint256,address)",
                    underlyingTokenToPid[_underlyingToken],
                    _depositAmount,
                    _vault
                )
            );
        }
    }

    /**
     * @inheritdoc IAdapter
     */
    function getWithdrawSomeCodes(
        address payable _vault,
        address _underlyingToken,
        address _masterChef,
        uint256 _redeemAmount
    ) public view override returns (bytes[] memory _codes) {
        if (_redeemAmount > 0) {
            _codes = new bytes[](1);
            _codes[0] = abi.encode(
                _masterChef,
                abi.encodeWithSignature(
                    "withdraw(uint256,uint256,address)",
                    underlyingTokenToPid[_underlyingToken],
                    _redeemAmount,
                    _vault
                )
            );
        }
    }

    /**
     * @inheritdoc IAdapter
     */
    function getPoolValue(address _masterChef, address _underlyingToken) public view override returns (uint256) {
        return IERC20(_underlyingToken).balanceOf(_masterChef);
    }

    /**
     * @inheritdoc IAdapter
     */
    function getLiquidityPoolToken(address _underlyingToken, address) public pure override returns (address) {
        return _underlyingToken;
    }

    /**
     * @inheritdoc IAdapter
     */
    function getAllAmountInToken(
        address payable _vault,
        address _underlyingToken,
        address _masterChef
    ) public view override returns (uint256) {
        (uint256 _amount, ) = ISushiswapMasterChefV2(_masterChef).userInfo(
            underlyingTokenToPid[_underlyingToken],
            _vault
        );
        return _amount;
    }

    /**
     * @inheritdoc IAdapter
     */
    function getLiquidityPoolTokenBalance(
        address payable _vault,
        address _underlyingToken,
        address _masterChef
    ) public view override returns (uint256) {
        (uint256 _amount, ) = ISushiswapMasterChefV2(_masterChef).userInfo(
            underlyingTokenToPid[_underlyingToken],
            _vault
        );
        return _amount;
    }

    /**
     * @inheritdoc IAdapter
     */
    function getRewardToken(address _masterChef) public view override returns (address) {
        return ISushiswapMasterChefV2(_masterChef).SUSHI();
    }

    /**
     * @inheritdoc IAdapterHarvestReward
     */
    function getUnclaimedRewardTokenAmount(
        address payable _vault,
        address _masterChef,
        address _underlyingToken
    ) public view override returns (uint256) {
        return ISushiswapMasterChefV2(_masterChef).pendingSushi(underlyingTokenToPid[_underlyingToken], _vault);
    }

    /**
     * @inheritdoc IAdapterHarvestReward
     */
    function getHarvestSomeCodes(
        address payable _vault,
        address _underlyingToken,
        address _masterChef,
        uint256 _rewardTokenAmount
    ) public view override returns (bytes[] memory) {
        return _getHarvestCodes(_vault, getRewardToken(_masterChef), _underlyingToken, _rewardTokenAmount);
    }

    /* solhint-disable no-empty-blocks */

    /**
     * @inheritdoc IAdapterHarvestReward
     */
    function getAddLiquidityCodes(address payable _vault, address _underlyingToken)
        public
        view
        override
        returns (bytes[] memory)
    {}

    /* solhint-enable no-empty-blocks */

    function _getDepositAmount(
        address _masterChef,
        address _underlyingToken,
        uint256 _amount
    ) internal view returns (uint256) {
        uint256 _limit = maxDepositProtocolMode == MaxExposure.Pct
            ? _getMaxDepositAmountByPct(_masterChef, _underlyingToken)
            : maxDepositAmount[_masterChef][_underlyingToken];
        return _amount > _limit ? _limit : _amount;
    }

    function _getMaxDepositAmountByPct(address _masterChef, address _underlyingToken) internal view returns (uint256) {
        uint256 _poolValue = getPoolValue(_masterChef, _underlyingToken);
        uint256 _poolPct = maxDepositPoolPct[_underlyingToken];
        uint256 _limit = _poolPct == 0
            ? (_poolValue * maxDepositProtocolPct) / uint256(10000)
            : (_poolValue * _poolPct) / uint256(10000);
        return _limit;
    }

    /**
     * @dev Get the codes for harvesting the tokens using uniswap router
     * @param _vault Vault contract address
     * @param _rewardToken Reward token address
     * @param _underlyingToken Token address acting as underlying Asset for the vault contract
     * @param _rewardTokenAmount reward token amount to harvest
     * @return _codes List of harvest codes for harvesting reward tokens
     */
    function _getHarvestCodes(
        address payable _vault,
        address _rewardToken,
        address _underlyingToken,
        uint256 _rewardTokenAmount
    ) internal view returns (bytes[] memory _codes) {
        if (_rewardTokenAmount > 0) {
            uint256[] memory _amounts = IUniswapV2Router02(SUSHISWAP_ROUTER).getAmountsOut(
                _rewardTokenAmount,
                _getPath(_rewardToken, _underlyingToken)
            );
            if (_amounts[_amounts.length - 1] > 0) {
                _codes = new bytes[](3);
                _codes[0] = abi.encode(
                    _rewardToken,
                    abi.encodeCall(IERC20(_rewardToken).approve, (SUSHISWAP_ROUTER, uint256(0)))
                );
                _codes[1] = abi.encode(
                    _rewardToken,
                    abi.encodeCall(IERC20(_rewardToken).approve, (SUSHISWAP_ROUTER, _rewardTokenAmount))
                );
                _codes[2] = abi.encode(
                    SUSHISWAP_ROUTER,
                    abi.encodeCall(
                        IUniswapV2Router01(SUSHISWAP_ROUTER).swapExactTokensForTokens,
                        (
                            _rewardTokenAmount,
                            uint256(0),
                            _getPath(_rewardToken, _underlyingToken),
                            _vault,
                            type(uint256).max
                        )
                    )
                );
            }
        }
    }

    /**
     * @dev Constructs the path for token swap on Uniswap
     * @param _initialToken The token to be swapped with
     * @param _finalToken The token to be swapped for
     * @return _path The array of tokens in the sequence to be swapped for
     */
    function _getPath(address _initialToken, address _finalToken) internal pure returns (address[] memory _path) {
        address _weth = IUniswapV2Router02(SUSHISWAP_ROUTER).WETH();
        if (_finalToken == _weth) {
            _path = new address[](2);
            _path[0] = _initialToken;
            _path[1] = _weth;
        } else if (_initialToken == _weth) {
            _path = new address[](2);
            _path[0] = _weth;
            _path[1] = _finalToken;
        } else {
            _path = new address[](3);
            _path[0] = _initialToken;
            _path[1] = _weth;
            _path[2] = _finalToken;
        }
    }

    /**
     * @dev Get the underlying token amount equivalent to reward token amount
     * @param _rewardToken Reward token address
     * @param _underlyingToken Token address acting as underlying Asset for the vault contract
     * @param _amount reward token balance amount
     * @return equivalent reward token balance in Underlying token value
     */
    function _getRewardBalanceInUnderlyingTokens(
        address _rewardToken,
        address _underlyingToken,
        uint256 _amount
    ) internal view returns (uint256) {
        try
            IUniswapV2Router02(SUSHISWAP_ROUTER).getAmountsOut(_amount, _getPath(_rewardToken, _underlyingToken))
        returns (uint256[] memory _amountsA) {
            return _amountsA[_amountsA.length - 1];
        } catch {
            return 0;
        }
    }
}
