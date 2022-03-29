// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./abstract/ReaperBaseStrategyv2.sol";
import "./interfaces/IFarmV2.sol";
import "./interfaces/IBeetVault.sol";
import "./interfaces/IBaseWeightedPool.sol";
import "./interfaces/IBasePool.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";

/**
 * @dev Farms the QiDao protocol for Qi rewards
 */
contract ReaperStrategyQiDao is ReaperBaseStrategyv2 {
    using SafeERC20Upgradeable for IERC20Upgradeable;

    // 3rd-party contract addresses
    address public constant BEET_VAULT = address(0x20dd72Ed959b6147912C2e529F0a0C651c33c9ce);
    address public constant MASTER_CHEF = address(0x230917f8a262bF9f2C3959eC495b11D1B7E1aFfC);

    /**
     * @dev Tokens Used:
     * {WFTM} - Required for liquidity routing when doing swaps.
     * {USDC} - Used for making the want LP token
     * {QI} - Reward token for compounding into want
     * {want} - The deposited token the strategy is maximizing
     * {underlyings} - Array of IAsset type to represent the underlying tokens of the pool.
     */
    address public constant WFTM = address(0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83);
    address public constant USDC = address(0x04068DA6C83AFCFA0e13ba15A6696662335D5B75);
    address public constant QI = address(0x68Aa691a8819B07988B18923F712F3f4C8d36346);
    address public constant want = address(0x985976228a4685Ac4eCb0cfdbEeD72154659B6d9);
    IAsset[] underlyings;

    // pools used to swap tokens
    bytes32 public constant WFTM_QI_POOL = 0x7ae6a223cde3a17e0b95626ef71a2db5f03f540a00020000000000000000008a;
    bytes32 public constant WFTM_USDC_POOL = 0xcdf68a4d525ba2e90fe959c74330430a5a6b8226000200000000000000000008;

    /**
     * @dev QiDao variables
     * {poolId} - ID of pool in which to deposit LP tokens in the {MASTER_CHEF}
     * {qiToWftmRatio} - Saves tha ratio of qi to wftm after making a swap, used to later estimate the harvest
     * {beetsPoolId} - bytes32 ID of the Beethoven-X pool corresponding to {want}
     * {usdcPosition} - Index of {USDC} in the Beethoven-X pool
     */
    uint256 public constant POOL_ID = 0;
    uint256 public qiToWftmRatio;
    bytes32 public beetsPoolId;
    uint256 public usdcPosition;

    /**
     * @dev Initializes the strategy. Sets parameters and saves routes.
     * @notice see documentation for each variable above its respective declaration.
     */
    function initialize(
        address _vault,
        address[] memory _feeRemitters,
        address[] memory _strategists
    ) public initializer {
        __ReaperBaseStrategy_init(_vault, _feeRemitters, _strategists);
        qiToWftmRatio = 1 ether; // Default to 1:1 qi:wftm (reasonably accurate)
        beetsPoolId = IBasePool(want).getPoolId();

        (IERC20Upgradeable[] memory tokens, , ) = IBeetVault(BEET_VAULT).getPoolTokens(beetsPoolId);
        for (uint256 i = 0; i < tokens.length; i++) {
            if (address(tokens[i]) == USDC) {
                usdcPosition = i;
            }

            underlyings.push(IAsset(address(tokens[i])));
        }
    }

    /**
     * @dev Function that puts the funds to work.
     *      It gets called whenever someone deposits in the strategy's vault contract.
     */
    function _deposit() internal override {
        uint256 wantBalance = IERC20Upgradeable(want).balanceOf(address(this));
        if (wantBalance != 0) {
            IERC20Upgradeable(want).safeIncreaseAllowance(MASTER_CHEF, wantBalance);
            IFarmV2(MASTER_CHEF).deposit(POOL_ID, wantBalance);
        }
    }

    /**
     * @dev Withdraws funds and sends them back to the vault.
     */
    function _withdraw(uint256 _amount) internal override {
        uint256 wantBal = IERC20Upgradeable(want).balanceOf(address(this));
        if (wantBal < _amount) {
            IFarmV2(MASTER_CHEF).withdraw(POOL_ID, _amount - wantBal);
        }

        IERC20Upgradeable(want).safeTransfer(vault, _amount);
    }

    /**
     * @dev Core function of the strat, in charge of collecting and re-investing rewards.
     *      1. Claims {QI} from the {MASTER_CHEF}.
     *      2. Swaps {QI} to {WFTM} using {BEET_VAULT}.
     *      3. Claims fees for the harvest caller and treasury.
     *      4. Swaps {WFTM} to {USDC} using {BEET_VAULT}.
     *      5. Creates the want LP token
     *      6. Deposits the want in {MASTER_CHEF} to farm
     */
    function _harvestCore() internal override {
        _claimRewards();
        _swapQiToWftm();
        _chargeFees();
        _swapWftmToUSDC();
         _joinPool();
        deposit();
    }

    /**
     * @dev Core harvest function. Claims the QI reward from the {MASTER_CHEF}.
     */
    function _claimRewards() internal {
        IFarmV2(MASTER_CHEF).deposit(POOL_ID, 0); // deposit 0 to claim rewards
    }

    /**
     * @dev Core harvest function. Swaps {QI} to {WFTM} using {WFTM_QI_POOL}.
     */
    function _swapQiToWftm() internal {
        uint256 qiBal = IERC20Upgradeable(QI).balanceOf(address(this));
        if (qiBal == 0) {
            return;
        }
        uint256 wftmBalBefore = IERC20Upgradeable(WFTM).balanceOf(address(this));
        _swap(qiBal, QI, WFTM, WFTM_QI_POOL);
        uint256 wftmBalAfter = IERC20Upgradeable(WFTM).balanceOf(address(this));
        uint256 wftmBalChange = wftmBalAfter - wftmBalBefore;
        qiToWftmRatio =  1 ether * qiBal  / wftmBalChange;
    }

    /**
     * @dev Core harvest function. Swaps {WFTM} to {USDC} using {WFTM_USDC_POOL}.
     */
    function _swapWftmToUSDC() internal {
        uint256 wftmBal = IERC20Upgradeable(WFTM).balanceOf(address(this));
        uint256 minSwapAmount = 1000000000000; // To prevent reverting on small amounts since USDC has 6 decimals only
        if (wftmBal < minSwapAmount) {
            return;
        }

        _swap(wftmBal, WFTM, USDC, WFTM_USDC_POOL);
    }

    function _swap(uint256 _amount, address _from, address _to, bytes32 _pool) internal {

        IBeetVault.SingleSwap memory singleSwap;
        singleSwap.poolId = _pool;
        singleSwap.kind = IBeetVault.SwapKind.GIVEN_IN;
        singleSwap.assetIn = IAsset(_from);
        singleSwap.assetOut = IAsset(_to);
        singleSwap.amount = _amount;
        singleSwap.userData = abi.encode(0);

        IBeetVault.FundManagement memory funds;
        funds.sender = address(this);
        funds.fromInternalBalance = false;
        funds.recipient = payable(address(this));
        funds.toInternalBalance = false;

        IERC20Upgradeable(_from).safeIncreaseAllowance(BEET_VAULT, _amount);
        IBeetVault(BEET_VAULT).swap(singleSwap, funds, 1, block.timestamp);
    }

    /**
     * @dev Core harvest function.
     *      Charges fees based on the amount of WFTM gained from reward
     */
    function _chargeFees() internal {
        IERC20Upgradeable wftm = IERC20Upgradeable(WFTM);
        uint256 wftmFee = (wftm.balanceOf(address(this)) * totalFee) / PERCENT_DIVISOR;
        if (wftmFee != 0) {
            uint256 callFeeToUser = (wftmFee * callFee) / PERCENT_DIVISOR;
            uint256 treasuryFeeToVault = (wftmFee * treasuryFee) / PERCENT_DIVISOR;
            uint256 feeToStrategist = (treasuryFeeToVault * strategistFee) / PERCENT_DIVISOR;
            treasuryFeeToVault -= feeToStrategist;

            wftm.safeTransfer(msg.sender, callFeeToUser);
            wftm.safeTransfer(treasury, treasuryFeeToVault);
            wftm.safeTransfer(strategistRemitter, feeToStrategist);
        }
    }

    /**
     * @dev Core harvest function. Joins {beetsPoolId} using {USDC} balance;
     */
    function _joinPool() internal {
        uint256 usdcBal = IERC20Upgradeable(USDC).balanceOf(address(this));
        if (usdcBal == 0) {
            return;
        }

        IBaseWeightedPool.JoinKind joinKind = IBaseWeightedPool.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT;
        uint256[] memory amountsIn = new uint256[](underlyings.length);
        amountsIn[usdcPosition] = usdcBal;
        uint256 minAmountOut = 1;
        bytes memory userData = abi.encode(joinKind, amountsIn, minAmountOut);

        IBeetVault.JoinPoolRequest memory request;
        request.assets = underlyings;
        request.maxAmountsIn = amountsIn;
        request.userData = userData;
        request.fromInternalBalance = false;

        IERC20Upgradeable(USDC).safeIncreaseAllowance(BEET_VAULT, usdcBal);
        IBeetVault(BEET_VAULT).joinPool(beetsPoolId, address(this), address(this), request);
    }

    /**
     * @dev Function to calculate the total {want} held by the strat.
     *      It takes into account both the funds in hand, plus the funds in the MasterChef.
     */
    function balanceOf() public view override returns (uint256) {
        (uint256 amount, ) = IFarmV2(MASTER_CHEF).userInfo(POOL_ID, address(this));
        return amount + IERC20Upgradeable(want).balanceOf(address(this));
    }

    /**
     * @dev Returns the approx amount of profit from harvesting.
     *      Profit is denominated in WFT, and takes fees into account.
     */
    function estimateHarvest() external view override returns (uint256 profit, uint256 callFeeToUser) {
        uint256 pendingReward = IFarmV2(MASTER_CHEF).pending(POOL_ID, address(this));
        uint256 totalRewards = pendingReward + IERC20Upgradeable(QI).balanceOf(address(this));
        uint256 estimatedWftmReward =  totalRewards * 1 ether / qiToWftmRatio;
        profit += estimatedWftmReward + IERC20Upgradeable(WFTM).balanceOf(address(this));

        uint256 wftmFee = (profit * totalFee) / PERCENT_DIVISOR;
        callFeeToUser = (wftmFee * callFee) / PERCENT_DIVISOR;
        profit -= wftmFee;
    }

    /**
     * @dev Function to retire the strategy. Claims all rewards and withdraws
     *      all principal from external contracts, and sends everything back to
     *      the vault. Can only be called by strategist or owner.
     *
     * Note: this is not an emergency withdraw function. For that, see panic().
     */
    function _retireStrat() internal override {
        (uint256 amount, ) = IFarmV2(MASTER_CHEF).userInfo(POOL_ID, address(this));
        IFarmV2(MASTER_CHEF).withdraw(POOL_ID, amount);
        _swapQiToWftm();
        _swapWftmToUSDC();
         _joinPool();
        uint256 wantBalance = IERC20Upgradeable(want).balanceOf(address(this));
        IERC20Upgradeable(want).safeTransfer(vault, wantBalance);
    }

    /**
     * Withdraws all funds leaving rewards behind.
     */
    function _reclaimWant() internal override {
        IFarmV2(MASTER_CHEF).emergencyWithdraw(POOL_ID);
    }
}
