// SPDX-License-Identifier:MIT

pragma solidity =0.8.11;

// libraries
import { Address } from "@openzeppelin/contracts-0.8.x/utils/Address.sol";

// helpers
import { AdapterModifiersBase } from "../../utils/AdapterModifiersBase.sol";

// interfaces
import { ISushiswapMasterChefV2 } from "@optyfi/defi-legos/ethereum/sushiswap/contracts/ISushiswapMasterChefV2.sol";
import { IERC20 } from "@openzeppelin/contracts-0.8.x/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts-0.8.x/token/ERC20/extensions/IERC20Metadata.sol";
import { IAdapter } from "@optyfi/defi-legos/interfaces/defiAdapters/contracts/IAdapter.sol";
import { IAdapterHarvestReward } from "@optyfi/defi-legos/interfaces/defiAdapters/contracts/IAdapterHarvestReward.sol";
import "@optyfi/defi-legos/interfaces/defiAdapters/contracts/IAdapterInvestLimit.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import { IOptyFiOracle } from "../../utils/optyfi-oracle/contracts/interfaces/IOptyFiOracle.sol";

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

    struct Pid {
        address underlyingToken;
        uint256 pid;
    }

    struct Tolerance {
        address underlyingToken;
        uint256 tolerance;
    }

    /** @notice List of Sushiswap pairs */
    address public constant YGG_WETH = address(0x99B42F2B49C395D2a77D973f6009aBb5d67dA343);
    address public constant WETH_ENS = address(0xa1181481bEb2dc5De0DaF2c85392d81C704BF75D);
    address public constant WETH_IMX = address(0x18Cd890F4e23422DC4aa8C2D6E0Bd3F3bD8873d8);
    address public constant WETH_JPEG = address(0xdB06a76733528761Eda47d356647297bC35a98BD);
    address public constant APE_USDT = address(0xB27C7b131Cf4915BeC6c4Bc1ce2F33f9EE434b9f);

    /** @notice Sushiswap router contract address */
    address public constant SUSHISWAP_ROUTER = address(0xd9e1cE17f2641f24aE83637ab66a2cca9C378B9F);

    /** @notice Denominator for basis points calculations */
    uint256 public constant DENOMINATOR = 10000;

    /** @notice max deposit value datatypes */
    MaxExposure public maxDepositProtocolMode;

    /** @notice max deposit's protocol value in percentage */
    uint256 public maxDepositProtocolPct; // basis points

    /** @notice  OptyFi Oracle contract address */
    IOptyFiOracle public optyFiOracle;

    /** @notice Maps liquidityPool to max deposit value in percentage */
    mapping(address => uint256) public maxDepositPoolPct; // basis points

    /** @notice Maps liquidityPool to max deposit value in absolute value for a specific token */
    mapping(address => mapping(address => uint256)) public maxDepositAmount;

    /** @notice Maps underlyingToken to the ID of its pool */
    mapping(address => uint256) public underlyingTokenToPid;

    /** @notice Maps underlying token to maximum price deviation */
    mapping(address => uint256) public underlyingTokenToTolerance;

    constructor(address _registry, address _optyFiOracle) AdapterModifiersBase(_registry) {
        maxDepositProtocolPct = uint256(10000); // 100% (basis points)
        maxDepositProtocolMode = MaxExposure.Pct;
        underlyingTokenToPid[YGG_WETH] = uint256(6);
        underlyingTokenToPid[WETH_ENS] = uint256(24);
        underlyingTokenToPid[WETH_IMX] = uint256(27);
        underlyingTokenToPid[WETH_JPEG] = uint256(54);
        underlyingTokenToPid[APE_USDT] = uint256(55);
        optyFiOracle = IOptyFiOracle(_optyFiOracle);
    }

    /**
     * @notice Sets the OptyFi Oracle contract
     * @param _optyFiOracle OptyFi Oracle contract address
     */
    function setOptyFiOracle(address _optyFiOracle) external onlyOperator {
        optyFiOracle = IOptyFiOracle(_optyFiOracle);
    }

    /**
     * @notice Sets the price deviation tolerance for a set of underlying tokens
     * @param _tolerances array of Tolerance structs that links underlying tokens to tolerances
     */
    function setUnderlyingTokenToTolerance(Tolerance[] calldata _tolerances) external onlyRiskOperator {
        uint256 _len = _tolerances.length;
        for (uint256 i; i < _len; i++) {
            underlyingTokenToTolerance[_tolerances[i].underlyingToken] = _tolerances[i].tolerance;
        }
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
        uint256 _pid;
        if (_nSteps == uint256(1)) {
            _pid = underlyingTokenToPid[IVault(_vault).underlyingToken()];
        } else {
            _pid = underlyingTokenToPid[_investStrategySteps[_nSteps - 2].outputToken];
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
     * @param _pids array of structs that includes pair address and pool IDs
     */
    function setUnderlyingTokenToPid(Pid[] calldata _pids) public onlyOperator {
        uint256 _pidsLen = _pids.length;
        for (uint256 _i; _i < _pidsLen; _i++) {
            underlyingTokenToPid[_pids[_i].underlyingToken] = _pids[_i].pid;
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
                uint256 _minAmountOut = _calculateMinAmountOut(_rewardTokenAmount, _rewardToken, _underlyingToken);
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
                        IUniswapV2Router02(SUSHISWAP_ROUTER).swapExactTokensForTokens,
                        (
                            _rewardTokenAmount,
                            ((_minAmountOut * (DENOMINATOR - underlyingTokenToTolerance[_underlyingToken])) /
                                DENOMINATOR),
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
     * @dev Get the expected amount to receive of _tokenOut after swapping _tokenIn
     * @param _amountIn Amount of _tokenIn to be swapped for _tokenOut
     * @param _tokenIn Contract address of the origin token
     * @param _tokenOut Contract address of the destination token
     */
    function _calculateMinAmountOut(
        uint256 _amountIn,
        address _tokenIn,
        address _tokenOut
    ) internal view returns (uint256 _swapOutAmount) {
        uint256 price = optyFiOracle.getTokenPrice(_tokenIn, _tokenOut);
        require(price > uint256(0), "!price");
        uint256 decimalsIn = uint256(IERC20Metadata(_tokenIn).decimals());
        uint256 decimalsOut = uint256(IERC20Metadata(_tokenOut).decimals());
        _swapOutAmount = (_amountIn * price * 10**decimalsOut) / 10**(18 + decimalsIn);
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
}
